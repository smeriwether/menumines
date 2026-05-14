#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "shellwords"
require "time"
require "uri"

API_BASE = "https://api.appstoreconnect.apple.com"

def env_fetch(name)
  ENV.fetch(name) do
    warn "Missing required environment variable: #{name}"
    exit 1
  end
end

def base64url(data)
  Base64.urlsafe_encode64(data).delete("=")
end

def int_to_fixed_bytes(integer, width)
  bytes = []
  value = integer
  while value.positive?
    bytes.unshift(value & 0xff)
    value >>= 8
  end
  bytes.pack("C*").rjust(width, "\0")
end

def jwt_token
  key_id = env_fetch("ASC_KEY_ID")
  issuer_id = env_fetch("ASC_ISSUER_ID")
  key_path = env_fetch("ASC_API_KEY_PATH")
  key = OpenSSL::PKey.read(File.read(key_path))
  now = Time.now.to_i

  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = {
    iss: issuer_id,
    iat: now - 30,
    exp: now + 600,
    aud: "appstoreconnect-v1"
  }

  signing_input = "#{base64url(JSON.generate(header))}.#{base64url(JSON.generate(payload))}"
  digest = OpenSSL::Digest::SHA256.digest(signing_input)
  der_signature = key.dsa_sign_asn1(digest)
  signature = OpenSSL::ASN1.decode(der_signature)
  r = int_to_fixed_bytes(signature.value[0].value.to_i, 32)
  s = int_to_fixed_bytes(signature.value[1].value.to_i, 32)

  "#{signing_input}.#{base64url(r + s)}"
end

class AppStoreConnectClient
  def initialize
    @token = jwt_token
  end

  def get(path)
    request(Net::HTTP::Get, path)
  end

  def post(path, body)
    request(Net::HTTP::Post, path, body)
  end

  def delete(path)
    request(Net::HTTP::Delete, path)
  end

  private

  def request(request_class, path, body = nil)
    uri = URI.join(API_BASE, path)
    request = request_class.new(uri)
    request["Authorization"] = "Bearer #{@token}"
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body) if body

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    return {} if response.code.to_i == 204

    parsed = response.body.empty? ? {} : JSON.parse(response.body)
    return parsed if response.code.to_i.between?(200, 299)

    warn JSON.pretty_generate(parsed)
    warn "App Store Connect API request failed: #{request.method} #{uri} -> #{response.code}"
    exit 1
  end
end

def run_command(*args)
  puts args.shelljoin
  return if system(*args)

  warn "Command failed: #{args.shelljoin}"
  exit 1
end

def find_or_create_bundle_id(client, identifier:, name:)
  query = URI.encode_www_form("filter[identifier]" => identifier, "limit" => 200)
  response = client.get("/v1/bundleIds?#{query}")
  existing = response.fetch("data", []).find do |bundle_id|
    bundle_id.fetch("attributes").fetch("identifier") == identifier
  end
  return existing.fetch("id") if existing

  puts "Creating Bundle ID #{identifier}"
  created = client.post(
    "/v1/bundleIds",
    {
      data: {
        type: "bundleIds",
        attributes: {
          name: name,
          identifier: identifier,
          platform: "MAC_OS"
        }
      }
    }
  )
  created.fetch("data").fetch("id")
end

def create_certificate(client, temp_dir, certificate_type:, common_name:, prefix:)
  key_path = File.join(temp_dir, "#{prefix}.key")
  csr_path = File.join(temp_dir, "#{prefix}.csr")
  cer_path = File.join(temp_dir, "#{prefix}.cer")
  pem_path = File.join(temp_dir, "#{prefix}.pem")
  p12_path = File.join(temp_dir, "#{prefix}.p12")

  run_command(
    "openssl", "req",
    "-new", "-newkey", "rsa:2048", "-nodes",
    "-keyout", key_path,
    "-out", csr_path,
    "-subj", "/CN=#{common_name}/O=MenuMines/C=US"
  )

  response = client.post(
    "/v1/certificates",
    {
      data: {
        type: "certificates",
        attributes: {
          certificateType: certificate_type,
          csrContent: File.read(csr_path)
        }
      }
    }
  )

  certificate = response.fetch("data")
  certificate_der = Base64.decode64(certificate.fetch("attributes").fetch("certificateContent"))
  File.binwrite(cer_path, certificate_der)
  run_command("openssl", "x509", "-inform", "DER", "-in", cer_path, "-out", pem_path)
  run_command(
    "openssl", "pkcs12",
    "-export",
    "-inkey", key_path,
    "-in", pem_path,
    "-out", p12_path,
    "-passout", "pass:#{env_fetch("KEYCHAIN_PASSWORD")}"
  )

  x509 = OpenSSL::X509::Certificate.new(certificate_der)
  sha1 = OpenSSL::Digest::SHA1.hexdigest(certificate_der).upcase
  puts "Created #{certificate_type} certificate #{sha1}: #{x509.subject}"

  {
    id: certificate.fetch("id"),
    p12_path: p12_path,
    sha1: sha1
  }
end

def create_distribution_certificate(client, temp_dir)
  create_certificate(
    client,
    temp_dir,
    certificate_type: "DISTRIBUTION",
    common_name: "MenuMines CI Apple Distribution",
    prefix: "apple_distribution"
  )
end

def create_installer_certificate(client, temp_dir)
  create_certificate(
    client,
    temp_dir,
    certificate_type: "MAC_INSTALLER_DISTRIBUTION",
    common_name: "MenuMines CI Mac Installer Distribution",
    prefix: "mac_installer_distribution"
  )
end

def create_profile(client, name:, bundle_id:, certificate_id:, output_path:)
  response = client.post(
    "/v1/profiles",
    {
      data: {
        type: "profiles",
        attributes: {
          name: name,
          profileType: "MAC_APP_STORE"
        },
        relationships: {
          bundleId: {
            data: {
              type: "bundleIds",
              id: bundle_id
            }
          },
          certificates: {
            data: [
              {
                type: "certificates",
                id: certificate_id
              }
            ]
          }
        }
      }
    }
  )

  profile = response.fetch("data")
  File.binwrite(output_path, Base64.decode64(profile.fetch("attributes").fetch("profileContent")))
  {
    id: profile.fetch("id"),
    name: profile.fetch("attributes").fetch("name")
  }
end

def append_env(values)
  github_env = env_fetch("GITHUB_ENV")
  File.open(github_env, "a") do |file|
    values.each do |key, value|
      file.puts("#{key}=#{value}")
    end
  end
end

def prepare
  client = AppStoreConnectClient.new
  temp_dir = env_fetch("RUNNER_TEMP")
  run_id = env_fetch("GITHUB_RUN_ID")
  app_bundle_identifier = env_fetch("APP_BUNDLE_ID")

  FileUtils.mkdir_p(temp_dir)

  bundle_id = find_or_create_bundle_id(
    client,
    identifier: app_bundle_identifier,
    name: "MenuMines"
  )

  certificate = create_distribution_certificate(client, temp_dir)
  installer_certificate = create_installer_certificate(client, temp_dir)
  profile = create_profile(
    client,
    name: "MenuMines CI Mac App Store #{run_id}",
    bundle_id: bundle_id,
    certificate_id: certificate.fetch(:id),
    output_path: File.join(temp_dir, "mac.provisionprofile")
  )

  append_env(
    "APPLE_CERTIFICATE_PATH" => certificate.fetch(:p12_path),
    "APPLE_CERTIFICATE_PASSWORD" => env_fetch("KEYCHAIN_PASSWORD"),
    "APPLE_CERTIFICATE_SHA1" => certificate.fetch(:sha1),
    "INSTALLER_CERTIFICATE_PATH" => installer_certificate.fetch(:p12_path),
    "INSTALLER_CERTIFICATE_PASSWORD" => env_fetch("KEYCHAIN_PASSWORD"),
    "INSTALLER_CERTIFICATE_SHA1" => installer_certificate.fetch(:sha1),
    "APP_PROVISIONING_PROFILE_PATH" => File.join(temp_dir, "mac.provisionprofile"),
    "APP_PROFILE_NAME" => profile.fetch(:name),
    "ASC_CREATED_CERTIFICATE_IDS" => [certificate.fetch(:id), installer_certificate.fetch(:id)].join(","),
    "ASC_CREATED_PROFILE_IDS" => profile.fetch(:id)
  )
end

def cleanup
  client = AppStoreConnectClient.new
  profile_ids = ENV.fetch("ASC_CREATED_PROFILE_IDS", "").split(",").reject(&:empty?)
  certificate_ids = ENV.fetch("ASC_CREATED_CERTIFICATE_IDS", "").split(",").reject(&:empty?)

  profile_ids.each do |profile_id|
    puts "Deleting temporary provisioning profile #{profile_id}"
    client.delete("/v1/profiles/#{profile_id}")
  end

  certificate_ids.each do |certificate_id|
    puts "Revoking temporary distribution certificate #{certificate_id}"
    client.delete("/v1/certificates/#{certificate_id}")
  end
end

case ARGV.fetch(0, "prepare")
when "prepare"
  prepare
when "cleanup"
  cleanup
else
  warn "Usage: #{File.basename($PROGRAM_NAME)} [prepare|cleanup]"
  exit 1
end
