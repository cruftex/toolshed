#!/usr/bin/env bash
# Provenance records (metadata/provenance/<tool>.json): when, from where and over which TLS certificate each
# release was first verified. Functions only; source after lib/install.sh and lib/records.sh. Needs jq and openssl.

# jq filter: newest version first (numeric parts, missing parts count as zero, so 25.0.5.1 precedes 25.0.5), then
# platform; keys sorted inside each entry. New releases are thus prepended, so a discovery's diff only adds lines.
_provenance_canonical='to_entries
    | sort_by(.key | split("/") | [(.[0] | split(".") | map(-tonumber) | . + [0, 0, 0, 0, 0] | .[:5]), .[1]])
    | map(.value |= (to_entries | sort_by(.key) | from_entries)) | from_entries'

provenance_canonical() {
    jq --indent 2 "$_provenance_canonical"
}

# Print the server certificate from a peer file (IP, effective URL, then curl's %{certs}) as a JSON object:
# subject, issuer (signer), serial, validity, SHA-256 fingerprint and the issuing certificate's fingerprint.
# Prints nothing when the file holds no certificate.
provenance_tls() {
    local line pem='' fields issuer=''
    local -a certs=()
    while IFS= read -r line; do
        [[ $line != '-----BEGIN CERTIFICATE-----' ]] || pem=
        pem+=$line$'\n'
        [[ $line != '-----END CERTIFICATE-----' ]] || certs+=("$pem")
    done < <(tail -n +3 -- "$1")
    (( ${#certs[@]} )) || return 0
    fields=$(openssl x509 -noout -nameopt RFC2253 -dateopt iso_8601 -subject -issuer -serial -startdate -enddate \
        -fingerprint -sha256 <<< "${certs[0]}") || _installer_fail "Cannot read the TLS certificate in $1."
    if (( ${#certs[@]} > 1 )); then
        issuer=$(openssl x509 -noout -fingerprint -sha256 <<< "${certs[1]}") ||
            _installer_fail "Cannot read the issuing TLS certificate in $1."
    fi
    jq -Rn --arg issuer "$issuer" '
        def hex: sub("^[^=]*="; "") | gsub(":"; "") | ascii_downcase;
        [inputs | capture("^(?<k>[^=]+)=(?<v>.*)$") | {(.k): .v}] | add
        | {subject, issuer, serial: (.serial | ascii_downcase),
           not_before: (.notBefore | sub(" "; "T")), not_after: (.notAfter | sub(" "; "T")),
           sha256: ("=" + ."sha256 Fingerprint" | hex),
           issuer_sha256: (if $issuer == "" then null else $issuer | hex end)}' <<< "$fields"
}

# Record the first successful verification of NAME's KEY from SOURCE_URL without inventing history: create the
# entry, or only fill in missing peer details; then rewrite the file canonically (unchanged files are not touched).
record_provenance() {
    local name=$1 key=$2 source_url=$3 peer_file=$4 file="$toolshed_root/metadata/provenance/$1.json"
    local timestamp ip='' url='' tls='' staging ip_pattern='^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9a-fA-F:]*:[0-9a-fA-F:.]*$'
    local -a peer=()
    _installer_require jq openssl
    timestamp=$(recorded_timestamp "$name" "$key") || return
    if [[ -f $peer_file ]]; then
        mapfile -t -n 2 peer < "$peer_file"
        [[ ! ${peer[0]:-} =~ $ip_pattern ]] || ip=${peer[0]}
        url=${peer[1]:-}
        tls=$(provenance_tls "$peer_file") || return
    fi
    mkdir -p -- "${file%/*}"
    stage_directory staging "${file%/*}"
    if [[ -f $file ]]; then cat -- "$file"; else echo '{}'; fi | jq --indent 2 --arg key "$key" \
        --arg source "$source_url" --arg discovered "$timestamp" --arg observed "$_discovery_timestamp" \
        --arg ip "$ip" --arg url "$url" --argjson tls "${tls:-null}" '
        def null_if_empty: if . == "" then null else . end;
        ($ip | null_if_empty) as $ip | ($url | null_if_empty) as $url | (if $tls then {tls: $tls} else {} end) as $tls
        | if has($key) | not then
            .[$key] = {discovered_at: $discovered, checksum_url: $source, effective_url: $url, peer_ip: $ip} + $tls
          else .[$key] |= (.discovered_at = $discovered
            | if (.checksum_url // $source) == $source and $ip and $url
                 and ((.peer_ip // "") == "" or (.effective_url // "") == "")
              then . + {checksum_url: $source, peer_ip: $ip, effective_url: $url, peer_observed_at: $observed} + $tls
              else . end)
          end | '"$_provenance_canonical" > "$staging/provenance.json" || _installer_fail "Cannot update $file."
    cmp -s -- "$staging/provenance.json" "$file" || mv -f -- "$staging/provenance.json" "$file"
}
